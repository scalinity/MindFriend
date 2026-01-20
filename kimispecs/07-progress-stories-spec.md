# Progress Stories (Shareable Weekly Recap)

## Step 1: Feature Analysis

### Core purpose and value proposition
- Turn weekly insights into visual, shareable story cards that celebrate progress.
- Increase retention and organic sharing through positive reinforcement.

### Target users and use cases
- Users who enjoy reflecting on progress or sharing wins.
- Circle members who want lightweight updates.

### Dependencies / prerequisites
- Weekly summary generation (Edge Function).
- Mood, quest, exercise, and streak data.
- iOS share sheet integration.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Progress Stories
- **Description:** A weekly recap is transformed into 3-5 story cards with stats, highlights, and a positive tone. Stories can be saved, shared, or posted to a circle.
- **Business justification and user value:** Makes progress tangible and celebratory, improving retention and encouraging social growth.

### 2. Functional Requirements

#### FR1: Generate story cards from weekly data
- User stories:
  - As a user, I want a weekly story so I can see my progress at a glance.
  - As a user, I want the story to reflect my actual activity so it feels personal.
- Acceptance criteria:
  - Stories are generated weekly after the summary is created.
  - Each story contains a headline, a stat or highlight, and a supportive message.
  - If insufficient data exists, generate a minimal two-card story.

#### FR2: View and save stories
- User stories:
  - As a user, I want to swipe through story cards so it feels lightweight.
- Acceptance criteria:
  - Story cards are shown in a swipeable full-screen view.
  - Users can save stories to Photos.

#### FR3: Share stories
- User stories:
  - As a user, I want to share my story so I can celebrate with friends.
- Acceptance criteria:
  - Share sheet exports a rendered image of each card.
  - Users can share to circles with an optional caption.

### 3. Technical Specifications

#### Architecture and system design considerations
- Story data assembled server-side and delivered as structured payloads.
- Client renders cards locally and exports as images.

#### Data models and schemas (proposed)
- `weekly_stories`
  - `id` (uuid, pk)
  - `user_id` (uuid, fk)
  - `week_start` (date)
  - `cards` (jsonb)
  - `created_at` (timestamptz)

#### API endpoints / interfaces
- Edge Function `generate-weekly-story` (POST)
  - Input: `{ weekStart }`
  - Output: `{ cards[] }`
- Data service `getWeeklyStory(weekStart)`

#### Integration points with existing systems
- Uses weekly summary data and stats aggregation queries.
- Optional posting to circles feed as a story post.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions
- Full-screen story viewer with swipe gestures and a progress indicator.
- Share button and Save button on each card.
- Circle share modal with optional caption field.

#### User flow diagram (text)
1. Weekly summary completes.
2. Story notification appears on Home.
3. User opens story, swipes through cards.
4. User saves or shares.

#### Accessibility requirements
- Support Dynamic Type for text within cards.
- VoiceOver labels for navigation and share actions.

### 5. Edge Cases and Error Handling
- If story generation fails, show weekly summary instead.
- If sharing fails, show a non-blocking toast.

### 6. Testing Requirements
- Unit tests: card rendering, export to image.
- Integration tests: story fetch and persistence.
- UAT: open, swipe, save, share flow.

### 7. Implementation Notes
- Use a predefined card template library for consistent visuals.
- Avoid revealing sensitive details in shared stories.
- Apply privacy settings to disable sharing if user opted out.
